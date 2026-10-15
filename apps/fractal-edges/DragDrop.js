.pragma library

// Drag-to-reposition for tiled windows (pure, no Quickshell).
//
// Hyprland floats a tiled window while it is dragged and re-tiles it on release; the layout would
// then drop it next to the FOCUSED tile. The overlay instead works out where the pointer is (which
// tile, which side), shows that as a highlight, and tells the layout (`drop-intent`) so the window
// lands there when it is re-tiled.

var MOVE_PX = 8;           // pointer travel that makes a freshly floated window a drag
var GRACE_MS = 700;        // ...if it starts within this long of the float event

// Every tiled window of a status as [{ id, address, box }].
function tiles(status) {
    var out = [];
    if (!status || !status.tree)
        return out;
    (function walk(n) {
        if (n.kind === "window" && n.address && n.box)
            out.push({ id: n.id, address: n.address, box: n.box });
        (n.children || []).forEach(walk);
    })(status.tree);
    return out;
}

function inBox(p, b) {
    return p.x >= b.x && p.x < b.x + b.w && p.y >= b.y && p.y < b.y + b.h;
}

// The drop target under pointer `p`: { address, zone, box } with zone one of
// left / right / up / down / center, or null when the pointer is over no tile. `skip` is the
// dragged window's own address.
//   center  the middle of the tile (a SWAP_SIZE-wide box, 30% by default): the two windows swap
//   else    the side of the tile the pointer is on: whichever offset from the middle is larger
//           decides between left/right and up/down, so the window goes beside the tile and never
//           displaces the app underneath.
// opts.swapSize overrides the size of the swap area (a fraction of the tile; 0 = never swap).
var SWAP_SIZE = 0.3;

function targetAt(p, list, skip, opts) {
    var swapSize = opts && opts.swapSize !== undefined ? opts.swapSize : SWAP_SIZE;
    for (var i = 0; i < list.length; i++) {
        var t = list[i];
        if (t.address === skip || !inBox(p, t.box))
            continue;
        var ox = (p.x - t.box.x) / t.box.w - 0.5, oy = (p.y - t.box.y) / t.box.h - 0.5;
        var zone;
        if (swapSize > 0 && Math.abs(ox) <= swapSize / 2 && Math.abs(oy) <= swapSize / 2)
            zone = "center";
        else if (Math.abs(ox) >= Math.abs(oy))
            zone = ox < 0 ? "left" : "right";
        else
            zone = oy < 0 ? "up" : "down";
        return { address: t.address, zone: zone, box: t.box };
    }
    return null;
}

// Where the window would sit: half of the target on that side, or the whole tile for a swap.
function highlight(target) {
    var b = target.box;
    switch (target.zone) {
    case "left":
        return { x: b.x, y: b.y, w: b.w / 2, h: b.h };
    case "right":
        return { x: b.x + b.w / 2, y: b.y, w: b.w / 2, h: b.h };
    case "up":
        return { x: b.x, y: b.y, w: b.w, h: b.h / 2 };
    case "down":
        return { x: b.x, y: b.y + b.h / 2, w: b.w, h: b.h / 2 };
    }
    return { x: b.x, y: b.y, w: b.w, h: b.h };
}

// The layout command (the part inside hl.dsp.layout("...")).
function intentCommand(src, target) {
    if (!/^[A-Za-z0-9_x-]+$/.test(src))
        return "";
    if (!target)
        return "drop-intent clear";
    if (!/^[A-Za-z0-9_x-]+$/.test(target.address))
        return "";
    return "drop-intent " + src + " " + target.address + " " + target.zone;
}

// ---- drag detection ------------------------------------------------------------------------------
// A window is being dragged when it was a tile, was just floated, and the pointer then moves. A
// window you float on purpose (a key bind) sits still, so it never becomes a drag.

function create() {
    return { known: {}, cand: null, drag: null };
}

// Call with every status's addresses, so we know which windows were tiles.
function seeTiles(tr, list) {
    list.forEach(function (t) { tr.known[t.address] = true; });
}

// `changefloatingmode>>address,1|0`. Returns "start" | "end" | "".
function floatEvent(tr, address, floating, p, now) {
    if (floating) {
        if (tr.known[address] && !tr.drag) {
            tr.cand = { address: address, at: now, p: p };
            return "candidate";
        }
        return "";
    }
    if ((tr.cand && tr.cand.address === address) || (tr.drag && tr.drag.address === address)) {
        var was = !!tr.drag;
        tr.cand = null;
        tr.drag = null;
        return was ? "end" : "";
    }
    return "";
}

// A pointer sample. Returns { drag: address or "", p } (drag set while dragging).
function pointer(tr, p, now) {
    if (tr.cand && !tr.drag) {
        var moved = Math.abs(p.x - tr.cand.p.x) + Math.abs(p.y - tr.cand.p.y);
        if (moved >= MOVE_PX && now - tr.cand.at <= GRACE_MS) {
            tr.drag = { address: tr.cand.address };
            tr.cand = null;
        } else if (now - tr.cand.at > GRACE_MS) {
            tr.cand = null;          // it floated and sat still: a deliberate float
        }
    }
    return { drag: tr.drag ? tr.drag.address : "", p: p };
}

// The window vanished (closed): forget it.
function closed(tr, address) {
    delete tr.known[address];
    if (tr.cand && tr.cand.address === address)
        tr.cand = null;
    if (tr.drag && tr.drag.address === address)
        tr.drag = null;
}

function parseCursor(text) {
    try {
        var o = JSON.parse(text);
        return typeof o.x === "number" && typeof o.y === "number" ? { x: o.x, y: o.y } : null;
    } catch (e) {
        return null;
    }
}

// Address in `changefloatingmode>>ADDRESS,FLOATING` event data ("0x..." or bare hex).
function parseFloatEvent(data) {
    var m = /^(?:0x)?([0-9a-f]+),([01])$/i.exec(String(data || ""));
    return m ? { address: "0x" + m[1].toLowerCase(), floating: m[2] === "1" } : null;
}
