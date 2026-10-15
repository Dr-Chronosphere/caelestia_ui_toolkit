.pragma library

// Drag-to-merge detection for explorer windows. The compositor moves the window (Super+drag or a
// tiling drag), so the app never sees the pointer; instead it samples every window's geometry
// (hyprctl clients) and works out which one is being carried and what it is carried over.
// Pure functions + a small mutable tracker, no QML.

function area(r) {
    return Math.max(0, r.w) * Math.max(0, r.h);
}

function overlap(a, b) {
    var w = Math.min(a.x + a.w, b.x + b.w) - Math.max(a.x, b.x);
    var h = Math.min(a.y + a.h, b.y + b.h) - Math.max(a.y, b.y);
    return w > 0 && h > 0 ? w * h : 0;
}

function centerIn(a, b) {
    var cx = a.x + a.w / 2, cy = a.y + a.h / 2;
    return cx >= b.x && cx < b.x + b.w && cy >= b.y && cy < b.y + b.h;
}

// The window `moving` is "on top of": the one containing its centre on the same workspace; if
// several do, the one it overlaps most. Returns an id or "".
function targetFor(moving, others) {
    var best = "", bestOv = -1;
    others.forEach(function (o) {
        if (o.id === moving.id || o.workspace !== moving.workspace)
            return;
        if (!centerIn(moving, o))
            return;
        var ov = overlap(moving, o);
        if (ov > bestOv) {
            bestOv = ov;
            best = o.id;
        }
    });
    return best;
}

function create() {
    return { last: {}, movedAt: {}, dragging: "" };
}

// Feed one sample: wins = [{ id, x, y, w, h, workspace }], now in ms.
// Returns { dragging, target, drop }: the window being carried ("" if none), the window it is over
// ("" if none), and, once it has stayed still for `settleMs`, { from, to } to merge (only when it
// ended over a target). A move is a position change with no size change; resizes are ignored.
function update(tr, wins, now, opts) {
    opts = opts || {};
    var settleMs = opts.settleMs === undefined ? 450 : opts.settleMs;
    var minMove = opts.minMove === undefined ? 3 : opts.minMove;
    var byId = {};
    wins.forEach(function (w) {
        byId[w.id] = w;
        var p = tr.last[w.id];
        if (p) {
            var resized = Math.abs(p.w - w.w) > 1 || Math.abs(p.h - w.h) > 1;
            var moved = Math.abs(p.x - w.x) >= minMove || Math.abs(p.y - w.y) >= minMove;
            if (resized) {
                if (tr.dragging === w.id)
                    tr.dragging = "";
                delete tr.movedAt[w.id];
            } else if (moved) {
                tr.movedAt[w.id] = now;
                // the most recently moved window is the one being carried
                if (tr.dragging !== w.id)
                    tr.dragging = w.id;
            }
        }
        tr.last[w.id] = { x: w.x, y: w.y, w: w.w, h: w.h };
    });
    for (var id in tr.last) {
        if (!byId[id]) {
            delete tr.last[id];
            delete tr.movedAt[id];
            if (tr.dragging === id)
                tr.dragging = "";
        }
    }
    var out = { dragging: tr.dragging, target: "", drop: null };
    if (!tr.dragging)
        return out;
    var m = byId[tr.dragging];
    out.target = targetFor(m, wins);
    if (now - (tr.movedAt[tr.dragging] || 0) >= settleMs) {
        if (out.target)
            out.drop = { from: tr.dragging, to: out.target };
        tr.dragging = "";
        out.dragging = "";
        out.target = "";
    }
    return out;
}

// Title carrying a window's id so geometry samples can be matched to windows: "Files #3 — Docs".
function idFromTitle(title) {
    var m = /^Files #(\d+)/.exec(String(title || ""));
    return m ? m[1] : "";
}

// Windows of ours from `hyprctl clients -j` text. Hidden/unmapped ones are skipped.
function samples(clientsText) {
    var list;
    try {
        list = JSON.parse(clientsText);
    } catch (e) {
        return [];
    }
    if (!Array.isArray(list))
        return [];
    var out = [];
    list.forEach(function (c) {
        var id = idFromTitle(c.title);
        if (!id || c.mapped === false || c.hidden || !c.at || !c.size)
            return;
        out.push({ id: id, x: c.at[0], y: c.at[1], w: c.size[0], h: c.size[1], workspace: c.workspace ? c.workspace.id : 0 });
    });
    return out;
}
