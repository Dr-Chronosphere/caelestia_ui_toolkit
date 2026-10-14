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

// Mirrors MIN_WEIGHT / MAX_WEIGHT in fractal_tree.lua: the engine keeps each tile's weight in this
// range, which bounds how far an edge can move.
var MIN_WEIGHT = 0.2;
var MAX_WEIGHT = 5.0;

// The range of ratios (a's share of the pair's space) the engine will accept for two weights.
function limits(wa, wb) {
    var sum = wa + wb;
    if (!(sum > 0))
        return { lo: 0.05, hi: 0.95 };
    var lo = Math.max(MIN_WEIGHT, sum - MAX_WEIGHT);
    var hi = Math.min(MAX_WEIGHT, sum - MIN_WEIGHT);
    if (lo > hi)
        return { lo: wa / sum, hi: wa / sum };
    return { lo: lo / sum, hi: hi / sum };
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
                var lim = limits(a.weight, b.weight);
                seam.lo = lim.lo;
                seam.hi = lim.hi;
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

// Clamp a dragged ratio to what the engine accepts for this seam (or a safe default).
function clampRatio(r, seam) {
    var lo = seam && seam.lo !== undefined ? seam.lo : 0.05;
    var hi = seam && seam.hi !== undefined ? seam.hi : 0.95;
    return Math.min(hi, Math.max(lo, r));
}

// Rubber band: past the limits the displayed ratio gives way ever more slowly and never moves
// further than `give` px beyond the limit. Inside the limits it is the identity.
function rubberBand(raw, seam, give) {
    var lo = seam.lo !== undefined ? seam.lo : 0.05;
    var hi = seam.hi !== undefined ? seam.hi : 0.95;
    give = give === undefined ? 40 : give;
    if (raw >= lo && raw <= hi)
        return raw;
    var edge = raw > hi ? hi : lo;
    var d = Math.abs(raw - edge) * seam.span;              // px dragged past the limit
    var shown = give * (1 - Math.exp(-d / give));          // eases toward `give`
    return edge + (raw > hi ? 1 : -1) * shown / seam.span;
}

// The layout message that sets the edge to `ratio`.
function edgeCommand(seam, ratio) {
    return "edge " + seam.a + " " + seam.b + " " + clampRatio(ratio, seam).toFixed(4);
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

// --- Floating windows ---------------------------------------------------------------------
// Layer-shell surfaces (the handles) always render above every normal window, floating ones
// included. So handles must not exist where a floating window is on top of the tiled layout.

// Rects (layout coordinates, grown by `pad` px) of the floating windows that cover the tiled
// layout of monitor `monitorName`, from `hyprctl clients -j` and `hyprctl monitors -j`:
// floating, mapped, not hidden, on that monitor, and either on its active workspace, on its
// currently shown special workspace (scratchpad), or pinned (shown on every workspace).
function floatingRects(clientsText, monitorsText, monitorName, pad) {
    pad = pad === undefined ? 3 : pad;
    var clients, monitors;
    try {
        clients = JSON.parse(clientsText);
        monitors = JSON.parse(monitorsText);
    } catch (e) {
        return [];
    }
    if (!Array.isArray(clients) || !Array.isArray(monitors))
        return [];
    var mon = null;
    for (var i = 0; i < monitors.length; i++) {
        if (monitors[i].name === monitorName)
            mon = monitors[i];
    }
    if (!mon)
        return [];
    var activeId = mon.activeWorkspace ? mon.activeWorkspace.id : undefined;
    var specialId = mon.specialWorkspace && mon.specialWorkspace.id ? mon.specialWorkspace.id : 0;

    var out = [];
    for (var j = 0; j < clients.length; j++) {
        var c = clients[j];
        if (!c.floating || c.mapped === false || c.hidden || !c.at || !c.size || c.monitor !== mon.id)
            continue;
        var wsId = c.workspace ? c.workspace.id : undefined;
        var shown = c.pinned || wsId === activeId || (specialId !== 0 && wsId === specialId);
        if (!shown)
            continue;
        out.push({ x: c.at[0] - pad, y: c.at[1] - pad, w: c.size[0] + 2 * pad, h: c.size[1] + 2 * pad });
    }
    return out;
}

// Split the interval [from, to) into the parts not covered by `covered` ([a, b) pairs).
function uncovered(from, to, covered) {
    var cuts = covered
        .map(function (c) { return [Math.max(from, c[0]), Math.min(to, c[1])]; })
        .filter(function (c) { return c[1] > c[0]; })
        .sort(function (p, q) { return p[0] - q[0]; });
    var out = [];
    var pos = from;
    for (var i = 0; i < cuts.length; i++) {
        if (cuts[i][0] > pos)
            out.push([pos, cuts[i][0]]);
        pos = Math.max(pos, cuts[i][1]);
    }
    if (pos < to)
        out.push([pos, to]);
    return out;
}

// Cut a thin rect ({x, y, w, h}) that runs along `axis` ("x": vertical line, so it runs along y;
// "y": horizontal line, running along x) into the parts no blocker covers.
function clipRect(rect, axisOfSeam, blockers) {
    var along = axisOfSeam === "x" ? "y" : "x";           // direction the rect extends in
    var lenKey = along === "y" ? "h" : "w";
    var thickKey = along === "y" ? "w" : "h";
    var coverKey = along === "y" ? "x" : "y";
    var covered = [];
    for (var i = 0; i < blockers.length; i++) {
        var b = blockers[i];
        // only blockers that overlap the thin rect across its thickness matter
        if (b[coverKey] < rect[coverKey] + rect[thickKey] && b[coverKey] + b[thickKey] > rect[coverKey])
            covered.push([b[along], b[along] + b[lenKey]]);
    }
    return uncovered(rect[along], rect[along] + rect[lenKey], covered).map(function (iv) {
        var r = { x: rect.x, y: rect.y, w: rect.w, h: rect.h };
        r[along] = iv[0];
        r[lenKey] = iv[1] - iv[0];
        return r;
    });
}

// Handles with the floating-window-covered stretches removed. Pieces shorter than `minLen`
// are dropped (too small to grab). The drag maths (ratio, span) is unchanged per piece.
function clipSeams(seamList, blockers, minLen) {
    minLen = minLen === undefined ? 24 : minLen;
    if (!blockers || blockers.length === 0)
        return seamList;
    var out = [];
    seamList.forEach(function (s) {
        var pieces = clipRect(s, s.axis, blockers);
        pieces.forEach(function (r, i) {
            var len = s.axis === "x" ? r.h : r.w;
            if (len < minLen)
                return;
            var piece = {};
            for (var k in s)
                piece[k] = s[k];
            piece.x = r.x; piece.y = r.y; piece.w = r.w; piece.h = r.h;
            piece.key = s.key + "#" + i;
            out.push(piece);
        });
    });
    return out;
}

// The drag guide, clipped the same way. Coordinates are relative to the monitor origin.
// Returns an array of {x, y, w, h}.
function guideRects(seam, ratio, originX, originY, thickness, blockers) {
    var r = guideRect(seam, ratio, 0, 0, thickness);       // layout coordinates first
    var pieces = blockers && blockers.length ? clipRect(r, seam.axis, blockers) : [r];
    return pieces.map(function (p) {
        return { x: p.x - originX, y: p.y - originY, w: p.w, h: p.h };
    });
}

// True if any floating window is mapped and visible (used to decide whether to poll).
function hasFloating(clientsText) {
    var clients;
    try {
        clients = JSON.parse(clientsText);
    } catch (e) {
        return false;
    }
    return Array.isArray(clients) && clients.some(function (c) { return c.floating && c.mapped !== false && !c.hidden; });
}

// --- Smooth cuts around floating windows --------------------------------------------------------
// While dragging, the guide line is cut around floating windows. When the line slides past a
// window's side the cut must not pop in or out: each blocker has a "cut amount" t (0..1) that
// the host animates, and the cut it makes is its extent scaled by t around its centre.

// For each blocker: its extent along the line's direction and whether the (thin) line currently
// overlaps it across its thickness. `thin` is {x, y, w, h} in layout coordinates.
function blockerSpans(thin, axisOfSeam, blockers) {
    var along = axisOfSeam === "x" ? "y" : "x";
    var lenKey = along === "y" ? "h" : "w";
    var thickKey = along === "y" ? "w" : "h";
    var coverKey = along === "y" ? "x" : "y";
    return (blockers || []).map(function (b) {
        return {
            a: b[along],
            b: b[along] + b[lenKey],
            on: b[coverKey] < thin[coverKey] + thin[thickKey] && b[coverKey] + b[thickKey] > thin[coverKey]
        };
    });
}

// The pieces of the line left uncovered when blocker i is cut by amount
// prevT[i] + (targetT[i] - prevT[i]) * e   (e = animation progress 0..1, already eased).
// Returns rects in layout coordinates.
function guidePieces(thin, axisOfSeam, spans, prevT, targetT, e) {
    var along = axisOfSeam === "x" ? "y" : "x";
    var lenKey = along === "y" ? "h" : "w";
    var covered = [];
    for (var i = 0; i < spans.length; i++) {
        var t = prevT[i] + (targetT[i] - prevT[i]) * e;
        if (t > 0.001) {
            var centre = (spans[i].a + spans[i].b) / 2;
            var half = (spans[i].b - spans[i].a) / 2 * t;
            covered.push([centre - half, centre + half]);
        }
    }
    return uncovered(thin[along], thin[along] + thin[lenKey], covered).map(function (iv) {
        var r = { x: thin.x, y: thin.y, w: thin.w, h: thin.h };
        r[along] = iv[0];
        r[lenKey] = iv[1] - iv[0];
        return r;
    });
}

// The Lua for `hyprctl eval` that stops Hyprland playing its layer slide/fade animations on the
// overlay's surfaces (the guide line and handles are layer surfaces, so without this a "ghost"
// of the last frame slides away whenever one is hidden).
function layerRuleCommand() {
    return 'hl.layer_rule({ name = "fractal-edges-noanim", match = { namespace = "caelestia-fractal-(edge|guide)" }, no_anim = true })';
}
