.pragma library

// Pure geometry for the edge handles (no Quickshell, unit-testable).
//
// Input: the status JSON the (patched) fractal layout writes to
// $XDG_RUNTIME_DIR/fractal-wm/ws-<id>.json, in which every placed node carries a
// `box` in Hyprland layout coordinates.

function parse(text) {
    if (!text)
        return null;
    var s;
    try {
        s = JSON.parse(text);
    } catch (e) {
        return null;
    }
    if (!s || typeof s !== "object" || !s.tree || !s.area)
        return null;
    return s;
}

function isSplit(node) {
    return node.kind === "row" || node.kind === "column";
}

// One seam per pair of neighbouring shown children of every row/column.
// `grab` is the handle thickness in px (centred on the boundary).
//
// Each seam: {
//   key, container, a, b      ids (a is the first/left/top child)
//   axis                      "x" for a row (handle drags left/right), "y" for a column
//   x, y, w, h                handle rectangle, layout coordinates
//   ratio                     a's share of the pair's space now (0-1)
//   span                      combined size of a and b along the axis, px
// }
function seams(status, grab) {
    grab = grab || 16;
    var out = [];
    if (!status || !status.tree)
        return out;

    function walk(node) {
        var kids = node.children || [];
        if (isSplit(node)) {
            var shown = kids.filter(function (c) { return !!c.box; });
            for (var i = 0; i + 1 < shown.length; i++) {
                var a = shown[i], b = shown[i + 1];
                var row = node.kind === "row";
                var aSize = row ? a.box.w : a.box.h;
                var bSize = row ? b.box.w : b.box.h;
                var span = aSize + bSize;
                if (span <= 0)
                    continue;
                var seam = {
                    key: a.id + "|" + b.id,
                    container: node.id,
                    a: a.id,
                    b: b.id,
                    axis: row ? "x" : "y",
                    ratio: aSize / span,
                    span: span
                };
                if (row) {
                    var bx = b.box.x;
                    seam.x = bx - grab / 2;
                    seam.y = Math.max(a.box.y, b.box.y);
                    seam.w = grab;
                    seam.h = Math.min(a.box.y + a.box.h, b.box.y + b.box.h) - seam.y;
                } else {
                    var by = b.box.y;
                    seam.x = Math.max(a.box.x, b.box.x);
                    seam.y = by - grab / 2;
                    seam.w = Math.min(a.box.x + a.box.w, b.box.x + b.box.w) - seam.x;
                    seam.h = grab;
                }
                if (seam.w > 0 && seam.h > 0)
                    out.push(seam);
            }
        }
        for (var k = 0; k < kids.length; k++)
            walk(kids[k]);
    }
    walk(status.tree);
    return out;
}

// Clamp a dragged ratio so neither tile collapses completely.
function clampRatio(r) {
    return Math.min(0.95, Math.max(0.05, r));
}

// The layout message that sets the edge to `ratio`.
function edgeCommand(seam, ratio) {
    return "edge " + seam.a + " " + seam.b + " " + clampRatio(ratio).toFixed(4);
}

// Where to draw the guide line while a seam is being dragged: the seam's centre line moved
// to `ratio`, relative to the monitor at (originX, originY). Returns {x, y, w, h}.
function guideRect(seam, ratio, originX, originY, thickness) {
    thickness = thickness || 3;
    var shift = (ratio - seam.ratio) * seam.span;
    if (seam.axis === "x") {
        return {
            x: seam.x + seam.w / 2 + shift - originX - thickness / 2,
            y: seam.y - originY,
            w: thickness,
            h: seam.h
        };
    }
    return {
        x: seam.x - originX,
        y: seam.y + seam.h / 2 + shift - originY - thickness / 2,
        w: seam.w,
        h: thickness
    };
}

// --- Animation suspension ------------------------------------------------------------------
// Tiles ease toward each new size, so during a live drag they trail the pointer and the guide
// line ends up drawn over window contents. The host switches animations off for the duration of
// a drag and back on afterwards (only if they were on to begin with).

// `hyprctl getoption animations:enabled -j` -> true / false, or null if it cannot be read.
function parseAnimEnabled(text) {
    var o;
    try {
        o = JSON.parse(text);
    } catch (e) {
        return null;
    }
    if (!o || typeof o !== "object")
        return null;
    if (typeof o.int === "number")
        return o.int !== 0;
    if (typeof o.bool === "boolean")
        return o.bool;
    return null;
}

// The Lua expression for `hyprctl eval` that sets the global animation switch.
function animCommand(on) {
    return "hl.config({ animations = { enabled = " + (on ? "true" : "false") + " } })";
}
